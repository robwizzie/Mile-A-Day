import Combine
import SwiftUI

/// The intro tour: five quick steps that show what Mile A Day is before
/// anyone signs up (and replayable from the dashboard / Settings › App tour).
///
/// Layout: a full-bleed colour hero holding a live illustration of the step
/// (Flamey, real feed photos, the Today board, the Closet), and a curved dark
/// sheet below it with the app icon sitting on the curve, a "Step N" chip, a
/// headline and one line of copy. The hero and the copy swipe together; the
/// sheet, icon, dots and the round arrow button stay put, and the hero colour
/// blends between steps. Last step: a "Get started" pill.
///
/// Motion is time-based (`IntroBob` reads a `TimelineView`, paused off-page
/// and under Reduce Motion) so nothing can stall half-way. Each step's art
/// pops in once, the first time that step is shown.
struct OnboardingIntroView: View {
    /// Final-step CTA.
    var finishButtonTitle: String = "Get started"
    /// Pre-sign-up onboarding shows "I already have an account" under the CTA.
    var showsSignInLink: Bool = false
    /// Finished or skipped. The presenter persists "seen" and moves on.
    let onComplete: () -> Void

    @State private var page = 0
    @StateObject private var showcase = ShowcasePhotoStore.shared

    private let steps = IntroStep.all
    private var isLast: Bool { page >= steps.count - 1 }
    private var step: IntroStep { steps[min(page, steps.count - 1)] }

    static let sheetColor = Color(red: 0.075, green: 0.05, blue: 0.06)
    private let curve: CGFloat = 26
    private let iconSize: CGFloat = 64

    var body: some View {
        GeometryReader { geo in
            let topInset = geo.safeAreaInsets.top
            let bottomInset = geo.safeAreaInsets.bottom
            let fullHeight = geo.size.height + topInset + bottomInset
            // Hero takes ~58% but always leaves 380pt for the sheet (SE fits).
            let heroHeight = max(260, min(fullHeight * 0.58, fullHeight - 380))
            // Art starts under the Skip button (44pt bar) and stops 16pt above the icon.
            let artTop = topInset + 48
            let artHeight = max(140, heroHeight - artTop - curve - iconSize / 2 - 16)

            ZStack(alignment: .top) {
                heroBackdrop
                    .frame(height: heroHeight + curve)

                // Swiping content: art in the hero, copy in the sheet.
                TabView(selection: $page) {
                    ForEach(steps.indices, id: \.self) { index in
                        IntroStepPage(
                            step: steps[index],
                            index: index,
                            count: steps.count,
                            isActive: index == page,
                            artHeight: artHeight,
                            artTop: artTop,
                            textTop: heroHeight + iconSize / 2 + 18,
                            photos: showcase.photos
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
                .environment(\.introArtWidth, geo.size.width)
                .background(alignment: .top) {
                    // The sheet sits UNDER the paged content so both art
                    // (above it) and copy (on it) swipe as one page.
                    IntroSheetShape(curve: curve)
                        .fill(Self.sheetColor)
                        .padding(.top, heroHeight - curve)
                }

                appIcon
                    .padding(.top, heroHeight - curve - iconSize / 2)
                    .allowsHitTesting(false)

                topBar
                    .padding(.top, topInset + 4)

                VStack {
                    Spacer()
                    controls
                        .padding(.horizontal, 24)
                        .padding(.bottom, bottomInset + 14)
                }
            }
            .ignoresSafeArea()
        }
        .background(Self.sheetColor.ignoresSafeArea())
        // Local only: `preferredColorScheme` would flip the whole window.
        .environment(\.colorScheme, .dark)
        .task { await showcase.load() }
    }

    // MARK: - Hero backdrop

    private var heroBackdrop: some View {
        ZStack {
            LinearGradient(colors: step.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            // Soft light from the top so the art pops.
            RadialGradient(colors: [.white.opacity(0.18), .clear], center: .top,
                           startRadius: 0, endRadius: 360)
        }
        .animation(.easeInOut(duration: 0.45), value: page)
    }

    private var appIcon: some View {
        Image("mad-logo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: iconSize, height: iconSize)
            .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous))
            // No frame ring: the icon sits straight on the crest.
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .accessibilityHidden(true)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Spacer()
            if !isLast {
                Button("Skip") { onComplete() }
                    .madFont(size: 16, weight: .semibold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.18)))
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        if isLast {
            VStack(spacing: 14) {
                Button {
                    MADHaptics.success()
                    onComplete()
                } label: {
                    Text(finishButtonTitle)
                        .madFont(size: 18, weight: .bold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(Capsule().fill(MADTheme.Colors.madRed))
                }
                if showsSignInLink {
                    Button(action: onComplete) {
                        (Text("Already have an account? ").foregroundColor(.white.opacity(0.55))
                         + Text("Sign in").foregroundColor(.white).bold())
                            .madFont(size: 15, design: .rounded, maxScale: 1.3)
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            HStack {
                dots
                Spacer()
                Button(action: advance) {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.12), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: CGFloat(page + 1) / CGFloat(steps.count))
                            .stroke(MADTheme.Colors.madRed, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Circle()
                            .fill(MADTheme.Colors.madRed)
                            .padding(7)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 68, height: 68)
                    .animation(.spring(response: 0.45, dampingFraction: 0.8), value: page)
                }
                .accessibilityLabel("Next")
            }
            .transition(.opacity)
        }
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(steps.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.white : Color.white.opacity(0.22))
                    .frame(width: index == page ? 24 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(page + 1) of \(steps.count)")
    }

    private func advance() {
        MADHaptics.tap()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            page = min(page + 1, steps.count - 1)
        }
    }
}

// MARK: - Steps

struct IntroStep {
    enum Art { case welcome, flamey, tracking, feed, friends, rewards }

    let art: Art
    let headline: String
    let body: String
    /// Hero gradient, always in the Mile A Day family (ember reds/oranges; the
    /// friends step borrows the app's "out walking now" blue).
    let colors: [Color]

    static let all: [IntroStep] = [
        IntroStep(art: .welcome,
                  headline: "A mile a day.",
                  body: "Walk or run a mile a day, build a streak, and keep it going with friends.",
                  colors: [Color(red: 0.93, green: 0.33, blue: 0.30), Color(red: 0.62, green: 0.12, blue: 0.22)]),
        IntroStep(art: .flamey,
                  headline: "Meet Flamey",
                  body: "He's your streak. He burns down as the day goes and blazes once your mile is in.",
                  colors: [Color(red: 1.0, green: 0.58, blue: 0.24), Color(red: 0.85, green: 0.25, blue: 0.27)]),
        IntroStep(art: .tracking,
                  headline: "Tracking is one tap",
                  body: "Start a walk on your phone or Apple Watch, or just go: Health walks count on their own. Widgets keep your streak in sight.",
                  colors: [Color(red: 0.96, green: 0.42, blue: 0.34), Color(red: 0.52, green: 0.14, blue: 0.36)]),
        IntroStep(art: .feed,
                  headline: "Show off your walk",
                  body: "Snap a photo after your mile. Friends see it in their feed and hype you up.",
                  colors: [Color(red: 0.88, green: 0.27, blue: 0.42), Color(red: 0.45, green: 0.10, blue: 0.30)]),
        IntroStep(art: .friends,
                  headline: "Keep each other going",
                  body: "See who's done today, nudge anyone running out of time, or walk together live.",
                  colors: [Color(red: 0.25, green: 0.56, blue: 0.95), Color(red: 0.16, green: 0.20, blue: 0.55)]),
        IntroStep(art: .rewards,
                  headline: "Win, collect, dress up",
                  body: "Compete with friends, earn medals and unlock new looks for Flamey every month.",
                  colors: [Color(red: 0.98, green: 0.70, blue: 0.25), Color(red: 0.80, green: 0.28, blue: 0.22)])
    ]
}

// MARK: - One page

private struct IntroStepPage: View {
    let step: IntroStep
    let index: Int
    let count: Int
    let isActive: Bool
    let artHeight: CGFloat
    let artTop: CGFloat
    let textTop: CGFloat
    let photos: [ShowcasePhoto]

    /// Pops once, the first time this step is on screen.
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .top) {
            art
                .frame(maxWidth: .infinity)
                .frame(height: artHeight)
                .padding(.top, artTop)
                .environment(\.introShown, shown)
                .environment(\.introActive, isActive)

            VStack(alignment: .leading, spacing: 12) {
                Text("Step \(index + 1)")
                    .madFont(size: 13, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(step.colors[0])
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(step.colors[0].opacity(0.16)))

                Text(step.headline)
                    .madFont(size: 32, weight: .heavy, design: .rounded, maxScale: 1.25)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)

                Text(step.body)
                    .madFont(size: 16, weight: .medium, design: .rounded, maxScale: 1.25)
                    .foregroundColor(.white.opacity(0.62))
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, textTop)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        // Insets are applied by hand (topInset/textTop); the pager must not add them again.
        .ignoresSafeArea()
        .onAppear { if isActive { reveal() } }
        .onChange(of: isActive) { _, active in if active { reveal() } }
    }

    private func reveal() {
        guard !shown else { return }
        // Next turn, so the first frame lays out before the springs start.
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { shown = true }
        }
    }

    @ViewBuilder
    private var art: some View {
        switch step.art {
        case .welcome: IntroWelcomeArt(height: artHeight)
        case .flamey: IntroFlameyArt(height: artHeight)
        case .tracking: IntroTrackingArt(height: artHeight)
        case .feed: IntroFeedArt(height: artHeight, photos: photos)
        case .friends: IntroFriendsArt(height: artHeight)
        case .rewards: IntroRewardsArt(height: artHeight)
        }
    }
}

// MARK: - Shared art pieces

private struct IntroShownKey: EnvironmentKey { static let defaultValue = true }
private struct IntroArtWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 375 }
private struct IntroActiveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var introShown: Bool {
        get { self[IntroShownKey.self] }
        set { self[IntroShownKey.self] = newValue }
    }
    var introActive: Bool {
        get { self[IntroActiveKey.self] }
        set { self[IntroActiveKey.self] = newValue }
    }
    /// The screen width the hero art lays out in (set by the containers).
    var introArtWidth: CGFloat {
        get { self[IntroArtWidthKey.self] }
        set { self[IntroArtWidthKey.self] = newValue }
    }
}

/// Keeps a floating chip's centre far enough from the screen edge that its
/// text never clips (320pt phones and wide art on Pro Max alike). The width is
/// estimated from the text: 14pt bold rounded averages ~8.4pt a character.
func introClampX(_ x: CGFloat, _ text: String, width: CGFloat) -> CGFloat {
    let half = CGFloat(text.count) * 4.2 + 16
    let limit = max(0, width / 2 - half - 10)
    return min(max(x, -limit), limit)
}

/// Gentle float, a pure function of the clock. Paused off-page / Reduce Motion.
struct IntroBob: ViewModifier {
    var amplitude: CGFloat = 6
    var period: Double = 3.2
    var phase: Double = 0
    @Environment(\.introActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            content.offset(y: CGFloat(sin((t / period + phase) * 2 * .pi)) * amplitude)
        }
    }
}

/// Pops in (scale + fade) with a stagger once the page is shown.
struct IntroPop: ViewModifier {
    var delay: Double = 0
    @Environment(\.introShown) private var shown

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
            .animation(.spring(response: 0.55, dampingFraction: 0.68).delay(delay), value: shown)
    }
}

extension View {
    func introBob(_ amplitude: CGFloat = 6, period: Double = 3.2, phase: Double = 0) -> some View {
        modifier(IntroBob(amplitude: amplitude, period: period, phase: phase))
    }
    func introPop(_ delay: Double = 0) -> some View { modifier(IntroPop(delay: delay)) }
}

/// A white pill label floating over the hero ("🔥 128 days").
struct IntroChip: View {
    let text: String
    var tint: Color = Color(red: 0.12, green: 0.08, blue: 0.09)

    var body: some View {
        Text(text)
            .madFont(size: 14, weight: .bold, design: .rounded, maxScale: 1.2)
            .foregroundColor(tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.white))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
    }
}

func introMiles(_ miles: Double) -> String {
    let unit = DistanceUnits.current
    return String(format: "%.2f %@", miles * unit.perMile, unit.abbreviation)
}

// MARK: - Step 1: welcome

private struct IntroWelcomeArt: View {
    let height: CGFloat
    @Environment(\.introArtWidth) private var artWidth

    var body: some View {
        let flame = min(height * 0.62, 240)
        ZStack {
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 10)
                .frame(width: flame * 1.18, height: flame * 1.18)
                .introPop(0)
            Circle()
                .trim(from: 0, to: 0.78)
                .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: flame * 1.18, height: flame * 1.18)
                .introPop(0.05)

            FlameBuddyView(health: .blazing, size: flame * 0.82, showsMoodBubble: false)
                .frame(width: flame * 0.82, height: flame * 0.82)
                .introPop(0.1)
                .introBob(5, period: 3.6)

            IntroChip(text: "🔥 128 day streak")
                .introBob(6, period: 3.0, phase: 0.2)
                .introPop(0.25)
                .offset(x: introClampX(-flame * 0.62, "🔥 128 day streak", width: artWidth), y: -flame * 0.42)
            IntroChip(text: "✓ " + introMiles(1.02) + " today", tint: Color(red: 0.15, green: 0.55, blue: 0.3))
                .introBob(6, period: 3.4, phase: 0.6)
                .introPop(0.35)
                .offset(x: introClampX(flame * 0.58, "✓ 1.02 mi today", width: artWidth), y: flame * 0.40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Step 2: Flamey

private struct IntroFlameyArt: View {
    let height: CGFloat

    var body: some View {
        let big = min(height * 0.62, 230)
        HStack(alignment: .bottom, spacing: 18) {
            VStack(spacing: 10) {
                FlameBuddyView(health: .low, size: big * 0.62, showsMoodBubble: false)
                    .frame(width: big * 0.62, height: big * 0.62)
                    .introBob(3, period: 2.6)
                IntroChip(text: "3h 20m left", tint: MADTheme.Colors.madRed)
            }
            .introPop(0.05)

            Image(systemName: "arrow.right")
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(.white.opacity(0.85))
                .padding(.bottom, big * 0.35)
                .introPop(0.15)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                FlameBuddyView(health: .blazing, size: big, showsMoodBubble: false)
                    .frame(width: big, height: big)
                    .introBob(5, period: 3.4, phase: 0.3)
                IntroChip(text: "Mile done ✓", tint: Color(red: 0.15, green: 0.55, blue: 0.3))
            }
            .introPop(0.25)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Step 3: tracking, Apple Watch, widgets

/// The three places a mile gets counted, side by side: the Watch app on the
/// left, the phone tracker in the middle (its ring counting up), a home
/// screen widget with Flamey on the right.
private struct IntroTrackingArt: View {
    let height: CGFloat
    @Environment(\.introArtWidth) private var artWidth

    var body: some View {
        // Phone card is the hero; watch and widget tuck in beside it. A short
        // hero (SE) drops the Health chip and gives the phone its room.
        let roomy = height >= 200
        let phoneH = min(height - (roomy ? 44 : 4), 220)
        let phoneW = phoneH * 0.56
        let side = min(phoneW * 0.78, (artWidth - phoneW - 40) / 2 + 18)
        ZStack {
            IntroPhoneTracker(width: phoneW, height: phoneH)
                .introPop(0)
            IntroWatch(size: side)
                .rotationEffect(.degrees(-8))
                .offset(x: -(phoneW / 2 + side * 0.42), y: phoneH * 0.18)
                .introPop(0.15)
                .introBob(4, period: 3.2)
            IntroWidget(size: side)
                .rotationEffect(.degrees(7))
                .offset(x: phoneW / 2 + side * 0.42, y: -phoneH * 0.16)
                .introPop(0.25)
                .introBob(4, period: 3.6, phase: 0.4)
            if roomy {
                IntroChip(text: "❤️ Counts from Apple Health")
                    .introPop(0.4)
                    .offset(y: phoneH / 2 + 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Today's mile ring counting up: a pure function of the clock (paused off
/// page / Reduce Motion via `IntroBob`'s rules), looping every few seconds.
private struct IntroMileRing: View {
    let size: CGFloat
    var lineWidth: CGFloat = 8
    var showsLabel = true
    @Environment(\.introActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !active)) { context in
            let cycle = 4.0
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
            // Climb to the full mile over 3s, hold, repeat.
            let p = reduceMotion ? 0.62 : min(1, t / 3.0)
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(p >= 1 ? Color(red: 0.30, green: 0.82, blue: 0.48) : MADTheme.Colors.madRed,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if showsLabel {
                    VStack(spacing: 0) {
                        Text(String(format: "%.2f", p * DistanceUnits.current.perMile))
                            .font(.system(size: size * 0.26, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                        Text(DistanceUnits.current.abbreviation)
                            .font(.system(size: size * 0.11, weight: .bold, design: .rounded))
                            .opacity(0.6)
                    }
                    .foregroundColor(.white)
                }
            }
            .frame(width: size, height: size)
        }
    }
}

private struct IntroPhoneTracker: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: height * 0.05) {
            Text("Walking")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
            IntroMileRing(size: width * 0.72, lineWidth: width * 0.06)
            Text("End")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: width * 0.62, height: height * 0.13)
                .background(Capsule().fill(MADTheme.Colors.madRed))
        }
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: width * 0.16, style: .continuous)
            .fill(Color(red: 0.08, green: 0.05, blue: 0.06)))
        .overlay(RoundedRectangle(cornerRadius: width * 0.16, style: .continuous)
            .stroke(.white.opacity(0.18), lineWidth: 3))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        .accessibilityHidden(true)
    }
}

/// An Apple Watch drawn in shapes (no Apple artwork): band, case, the ring.
private struct IntroWatch: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(Color(red: 0.16, green: 0.12, blue: 0.14))
                .frame(width: size * 0.56, height: size * 1.5)
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(.black)
                .frame(width: size * 0.84, height: size)
                .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .stroke(.white.opacity(0.25), lineWidth: 2))
            IntroMileRing(size: size * 0.62, lineWidth: size * 0.07)
        }
        .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
        .accessibilityHidden(true)
    }
}

/// A small home screen widget: Flamey and the streak.
private struct IntroWidget: View {
    let size: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            FlameBuddyView(health: .blazing, size: size * 0.52, still: true, showsMoodBubble: false)
                .frame(width: size * 0.52, height: size * 0.52)
            Text("🔥 535")
                .font(.system(size: size * 0.15, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.12, blue: 0.15),
                                          Color(red: 0.10, green: 0.05, blue: 0.07)],
                                 startPoint: .top, endPoint: .bottom)))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Step 4: feed photos

private struct IntroFeedArt: View {
    let height: CGFloat
    @Environment(\.introArtWidth) private var artWidth
    @Environment(\.introActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let photos: [ShowcasePhoto]

    /// Which photo is the front post. Every few seconds it's dealt away and
    /// the next one rises in; the prints behind show the two after it, so
    /// every photo gets its turn in front. Holds still off-page / under
    /// Reduce Motion.
    @State private var index = 0
    private let ticker = Timer.publish(every: 3.2, on: .main, in: .common).autoconnect()

    var body: some View {
        let width = min(height * 0.52, 190)
        let count = max(photos.count, 1)
        let front = index % count
        ZStack {
            backPrint(at: front + 2, width: width * 0.86)
                .rotationEffect(.degrees(9))
                .offset(x: width * 0.66, y: 14)
                .introPop(0.2)
            backPrint(at: front + 1, width: width * 0.86)
                .rotationEffect(.degrees(-9))
                .offset(x: -width * 0.66, y: 14)
                .introPop(0.12)
            // The front one is the feed's real post card, scaled down
            // (`PostCardView` .stacked: header, 4:5 photo, clap + comment +
            // share, streak pill, caption).
            IntroFeedPost(photo: photos.isEmpty ? nil : photos[front], height: height,
                          // Whole card (it's ~1.72× as tall as wide) so the
                          // clap row, streak and caption show; only a very
                          // short hero (SE) falls back to a peek.
                          maxWidth: max(min(artWidth * 0.58, 240, height / 1.72), min(150, artWidth * 0.5)))
                .id(front)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.88).combined(with: .opacity),
                    removal: .dealAway))
                .introPop(0)
                .introBob(4, period: 3.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(ticker) { _ in
            guard active, !reduceMotion, photos.count > 1 else { return }
            withAnimation(.spring(response: 0.62, dampingFraction: 0.84)) { index += 1 }
        }
    }

    /// A tilted print of the photo `offset` places after the front one,
    /// cross-fading when the rotation moves on.
    private func backPrint(at offset: Int, width: CGFloat) -> some View {
        let slot = photos.isEmpty ? offset % 3 : offset % photos.count
        return IntroPhotoCard(photo: photos.isEmpty ? nil : photos[slot], slot: slot, width: width)
            .id(slot)
            .transition(.opacity)
    }
}

/// The front post leaving: it tips and slides off to the left, like a card
/// dealt away, while the next one rises in its place.
private struct DealAway: ViewModifier {
    let progress: Double

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(-14 * progress))
            .offset(x: -170 * progress, y: 30 * progress)
            .opacity(1 - progress)
    }
}

private extension AnyTransition {
    static var dealAway: AnyTransition {
        .modifier(active: DealAway(progress: 1), identity: DealAway(progress: 0))
    }
}

/// A feed photo as a tilted print. Real showcase photo when loaded, a drawn
/// sample otherwise (signed-out devices, offline, or the showcase turned off).
private struct IntroPhotoCard: View {
    let photo: ShowcasePhoto?
    let slot: Int
    let width: CGFloat

    private static let samples: [(name: String, miles: Double, colors: [Color])] = [
        ("rob", 1.02, [Color(red: 0.98, green: 0.62, blue: 0.35), Color(red: 0.85, green: 0.28, blue: 0.36)]),
        ("dave", 1.21, [Color(red: 0.36, green: 0.62, blue: 0.95), Color(red: 0.25, green: 0.30, blue: 0.62)]),
        ("mad", 2.03, [Color(red: 0.40, green: 0.78, blue: 0.52), Color(red: 0.16, green: 0.45, blue: 0.40)])
    ]

    private var sample: (name: String, miles: Double, colors: [Color]) {
        Self.samples[slot % Self.samples.count]
    }

    var body: some View {
        let height = width * 1.25
        ZStack(alignment: .bottomLeading) {
            image
                .frame(width: width, height: height)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 1) {
                Text(photo?.username ?? sample.name)
                    .madFont(size: 13, weight: .bold, design: .rounded, maxScale: 1.1)
                Text(introMiles(photo?.distance ?? sample.miles))
                    .madFont(size: 12, weight: .semibold, design: .rounded, maxScale: 1.1)
                    .opacity(0.85)
            }
            .foregroundColor(.white)
            .lineLimit(1)
            .padding(10)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white, lineWidth: 3))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
        .accessibilityHidden(true)
    }

    /// Just the photo (or drawn sample), for the feed post to reuse.
    static func photoFace(photo: ShowcasePhoto?, slot: Int, width: CGFloat, height: CGFloat) -> some View {
        IntroPhotoCard(photo: photo, slot: slot, width: width)
            .image
            .frame(width: width, height: height)
            .clipped()
    }

    @ViewBuilder
    fileprivate var image: some View {
        if let bundled = photo?.bundledImage {
            Image(bundled).resizable().scaledToFill()
        } else if let url = photo?.imageURL {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    drawn
                }
            }
        } else {
            drawn
        }
    }

    private var drawn: some View {
        ZStack {
            LinearGradient(colors: sample.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: slot == 1 ? "figure.run" : "figure.walk")
                .font(.system(size: width * 0.34, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
                .offset(y: -width * 0.08)
        }
    }
}

/// The feed's post card in miniature, drawn to `PostCardView`'s `.stacked`
/// chrome scaled by `k` (its sizes are for a ~375pt-wide card): 40pt avatar,
/// 15pt bold name over "Walk · 1.02 mi · 2d", "…"; the photo edge to edge at
/// 4:5; the clap (`hands.clap.fill`, orange once hyped) with its count,
/// comment and share; the orange "N-day streak" pill; "name caption".
/// Taller than the hero allows, it peeks: clipped with a soft bottom fade,
/// like a feed scrolled to it.
private struct IntroFeedPost: View {
    let photo: ShowcasePhoto?
    let height: CGFloat
    let maxWidth: CGFloat

    var body: some View {
        let width = maxWidth
        let k = width / 375
        let natural = width * 1.72
        let peeks = natural > height
        let radius = 18 * max(k, 0.7)
        card(width: width, k: k)
            .frame(width: width, height: min(natural, height), alignment: .top)
            .clipped()
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: peeks ? 0.82 : 1),
                                       .init(color: .black.opacity(peeks ? 0 : 1), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .background(Color(red: 0.10, green: 0.06, blue: 0.08),
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            .accessibilityHidden(true)
    }

    private var name: String { photo?.username ?? "rob" }
    private var miles: Double { photo?.distance ?? 1.02 }
    private var caption: String { photo?.caption ?? "Sunset beach walk 🌅" }
    private var streak: Int { photo?.streak ?? 535 }
    private var accent: Color { MADTheme.workoutColor("walking") }

    private func card(width: CGFloat, k: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * k) {
            // Header
            HStack(spacing: 10 * k) {
                avatar
                    .frame(width: 40 * k, height: 40 * k)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 15 * k, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    HStack(spacing: 4 * k) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 10 * k, weight: .bold))
                            .foregroundColor(accent)
                        Text("Walk · " + introMiles(miles) + " · 2d")
                            .font(.system(size: 12 * k, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "ellipsis")
                    .font(.system(size: 15 * k, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.horizontal, 16 * k)
            .padding(.top, 12 * k)

            // Photo, edge to edge, 4:5
            IntroPhotoCard.photoFace(photo: photo, slot: 0, width: width, height: width * 1.25)

            // Clap + count, comment + count, share
            HStack(spacing: 2 * k) {
                HStack(spacing: 4 * k) {
                    Image(systemName: "hands.clap.fill")
                        .font(.system(size: 22 * k, weight: .medium))
                        .foregroundColor(.orange)
                    Text("12")
                        .font(.system(size: 14 * k, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.92))
                }
                .frame(minWidth: 44 * k, minHeight: 44 * k)
                HStack(spacing: 4 * k) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 20 * k))
                    Text("3")
                        .font(.system(size: 13 * k, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundColor(.white.opacity(0.62))
                .frame(minWidth: 44 * k, minHeight: 44 * k)
                Image(systemName: "paperplane")
                    .font(.system(size: 20 * k))
                    .foregroundColor(.white.opacity(0.62))
                    .frame(minWidth: 44 * k, minHeight: 44 * k)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6 * k)

            // Streak pill
            HStack(spacing: 4 * k) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 11 * k, weight: .bold))
                Text("\(streak)-day streak")
                    .font(.system(size: 12 * k, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 9 * k)
            .padding(.vertical, 4 * k)
            .background(Capsule().fill(Color.orange.opacity(0.16)))
            .padding(.horizontal, 18 * k)

            // Caption: bold name, then the caption
            (Text(name).bold() + Text(" " + caption))
                .font(.system(size: 14 * k, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(2)
                .padding(.horizontal, 18 * k)
                .padding(.bottom, 14 * k)
        }
        .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private var avatar: some View {
        // The poster's real (kid) photo: bundled for rob, so it's right even
        // offline or before the showcase loads.
        let fallback = Image("onboarding-friend-rob").resizable().scaledToFill()
        if let url = photo?.avatarURL {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    fallback
                }
            }
        } else {
            fallback
        }
    }
}

// MARK: - Step 5: friends (a Today board in miniature)

private struct IntroFriendsArt: View {
    let height: CGFloat
    @Environment(\.introArtWidth) private var artWidth

    var body: some View {
        // A short hero (SE) keeps the note to one line so the tiles stay big
        // enough to show the faces.
        let roomy = height >= 210
        let noteHeight: CGFloat = roomy ? 72 : 40
        // Three tiles + two 12pt gaps inside a 20pt gutter each side; a tile
        // is 1.25× as tall as it is wide.
        let tile = min((height - 14 - noteHeight) / 1.25, 112, (artWidth - 40 - 24) / 3)
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                IntroFriendTile(photo: "onboarding-friend-rob", name: "rob", kind: .done, size: tile)
                    .introPop(0)
                IntroFriendTile(photo: "onboarding-friend-dave", name: "dave", kind: .nudged, size: tile)
                    .introPop(0.1)
                    .introBob(4, period: 2.8)
                IntroFriendTile(photo: "onboarding-friend-mad", name: "mad", kind: .walking, size: tile)
                    .introPop(0.2)
            }
            IntroKidPhotoNote(roomy: roomy)
                .introPop(0.4)
                .introBob(3, period: 3.6, phase: 0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The team's profile pictures are their kid photos, and new users will see
/// baby pics all over the app: say so, and that theirs can be anything
/// (though a kid pic of themselves is the cool move).
private struct IntroKidPhotoNote: View {
    let roomy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("👶 Baby pics are our thing")
                .madFont(size: 14, weight: .heavy, design: .rounded, maxScale: 1.15)
            if roomy {
                Text("You'll see them all over the app. Any pic works for yours, but a kid pic is way cooler 😎")
                    .madFont(size: 12, weight: .medium, design: .rounded, maxScale: 1.15)
                    .opacity(0.7)
            }
        }
        .foregroundColor(Color(red: 0.12, green: 0.08, blue: 0.09))
        .lineLimit(3)
        .minimumScaleFactor(0.85)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 300, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        .rotationEffect(.degrees(-2))
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}

private struct IntroFriendTile: View {
    enum Kind { case done, nudged, walking }
    /// Asset name of the friend's profile picture (bundled, so it shows offline).
    let photo: String
    let name: String
    let kind: Kind
    let size: CGFloat

    private var ring: Color {
        switch kind {
        case .done: return Color(red: 0.30, green: 0.82, blue: 0.48)
        case .nudged: return MADTheme.Colors.madRed
        case .walking: return MADTheme.Colors.walkBlue
        }
    }

    private var label: String {
        switch kind {
        case .done: return "Done ✓"
        case .nudged: return "✓ Nudged"
        case .walking: return "Walking"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: kind == .done ? 1 : (kind == .walking ? 0.6 : 0.25))
                    .stroke(ring, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(photo)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
                    .padding(6)
            }
            .frame(width: size * 0.56, height: size * 0.56)
            .padding(.top, size * 0.12)

            // A small tile (short hero on an SE) keeps face + label only.
            if size >= 80 {
                Text(name)
                    .madFont(size: 13, weight: .semibold, design: .rounded, maxScale: 1.1)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .padding(.top, 5)
            }

            Spacer(minLength: 4)

            Text(label)
                .madFont(size: 12, weight: .bold, design: .rounded, maxScale: 1.1)
                .foregroundColor(kind == .done ? ring : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(kind == .done ? Color.clear : ring)
        }
        .frame(width: size, height: size * 1.25)
        .background(Color(red: 0.10, green: 0.08, blue: 0.10).opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Step 6: competitions, medals, Flamey's closet

private struct IntroRewardsArt: View {
    let height: CGFloat
    @Environment(\.introArtWidth) private var artWidth

    var body: some View {
        let flame = min(height * 0.6, 220)
        ZStack {
            IntroOutfitCycler(size: flame)
                .introPop(0.05)
                .introBob(4, period: 3.6)

            IntroChip(text: "🏆 Won the weekend duel")
                .introBob(5, period: 3.0, phase: 0.1)
                .introPop(0.2)
                .offset(x: introClampX(-flame * 0.5, "🏆 Won the weekend duel", width: artWidth), y: -flame * 0.5)
            IntroChip(text: "🏅 100 miles")
                .introBob(5, period: 3.3, phase: 0.5)
                .introPop(0.3)
                .offset(x: introClampX(flame * 0.7, "🏅 100 miles", width: artWidth), y: -flame * 0.05)
            IntroChip(text: "❄️ January flame")
                .introBob(5, period: 3.6, phase: 0.8)
                .introPop(0.4)
                .offset(x: introClampX(-flame * 0.55, "❄️ January flame", width: artWidth), y: flame * 0.42)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Flamey trying on a few looks: a free cap, a cape, a Monthly Flame and a
/// Plus look. Holds the first look under Reduce Motion or off-page.
private struct IntroOutfitCycler: View {
    let size: CGFloat
    @Environment(\.introActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    private let ticker = Timer.publish(every: 1.8, on: .main, in: .common).autoconnect()

    private static let items: [FlameyItem] = [.ballCap, .redCape, .frostbite, .electric, .astronautHelmet]

    var body: some View {
        let item = Self.items[index % Self.items.count]
        FlameBuddyView(health: .healthy, size: size, showsMoodBubble: false,
                       look: PlusLookShowcase.look(item), wardrobeReach: 0.9)
            .frame(width: size, height: size)
            .id(item)
            .transition(.asymmetric(insertion: .scale(scale: 0.86).combined(with: .opacity),
                                    removal: .opacity))
            .onReceive(ticker) { _ in
                guard active, !reduceMotion else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { index += 1 }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Sheet shape

/// The sheet's top edge bows up in the middle (peak at y = 0, corners at
/// y = `curve`), so the app icon can sit on the crest.
struct IntroSheetShape: Shape {
    var curve: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + curve))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + curve),
                          control: CGPoint(x: rect.midX, y: rect.minY - curve))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Showcase photos

/// One example feed photo from `GET /public/showcase` (an owner-chosen
/// allowlist, served signed to signed-out devices).
struct ShowcasePhoto: Decodable, Identifiable, Equatable {
    let post_id: String
    let media_url: String
    let caption: String?
    let distance: Double?
    let streak: Int?
    let username: String
    let profile_image_url: String?
    /// A copy of the photo shipped in the app (`onboarding-post-N`), so the
    /// feed step shows real photos instantly and offline. Never on the wire.
    var bundledImage: String? = nil

    var id: String { post_id }
    var imageURL: URL? { ProfileImageService.fullImageURL(for: media_url) }
    var avatarURL: URL? { ProfileImageService.fullImageURL(for: profile_image_url) }

    private enum CodingKeys: String, CodingKey {
        case post_id, media_url, caption, distance, streak, username, profile_image_url
    }

    /// rob's real posts from the default showcase allowlist, bundled:
    /// scenery and group walks rather than selfies, so the feed step shows
    /// what anyone's walks look like (a beach buddy walk with the front &
    /// back inset, a photo op with stickers, a sunset).
    static let bundled: [ShowcasePhoto] = [
        ShowcasePhoto(post_id: "07e8f0b6-7dd5-4bb7-ac64-7fd3f71c35a2", media_url: "",
                      caption: "Buddy walks on the beachhhhh", distance: 1.18, streak: 511,
                      username: "rob", profile_image_url: nil, bundledImage: "onboarding-post-1"),
        ShowcasePhoto(post_id: "81c1895c-3f0d-47ce-9872-321f4e50f4ab", media_url: "",
                      caption: "It was the perfect photo op 📸", distance: 3.14, streak: 520,
                      username: "rob", profile_image_url: nil, bundledImage: "onboarding-post-2"),
        ShowcasePhoto(post_id: "69626d63-32e6-4abd-8210-14d0d9017735", media_url: "",
                      caption: "Sunsets are too nice here 🌅", distance: 1.28, streak: 485,
                      username: "rob", profile_image_url: nil, bundledImage: "onboarding-post-3"),
        ShowcasePhoto(post_id: "0b9cde98-56fd-4c5a-a44b-e25ac11372a0", media_url: "",
                      caption: "Concert Mile 🎤", distance: 1.26, streak: 453,
                      username: "rob", profile_image_url: nil, bundledImage: "onboarding-post-4"),
        ShowcasePhoto(post_id: "04305ad4-2536-44bf-96d2-1b6fde894ae2", media_url: "",
                      caption: "@mad and Cape May 🌊", distance: 1.08, streak: 446,
                      username: "rob", profile_image_url: nil, bundledImage: "onboarding-post-5")
    ]
}

@MainActor
final class ShowcasePhotoStore: ObservableObject {
    static let shared = ShowcasePhotoStore()

    /// Starts on the bundled copies; the server's list only replaces them
    /// when the owner has picked different posts (`SHOWCASE_POST_IDS`).
    @Published private(set) var photos: [ShowcasePhoto] = ShowcasePhoto.bundled
    private var loading = false
    private var loaded = false

    private struct Response: Decodable { let photos: [ShowcasePhoto] }

    /// Fetch once per launch, then warm the image cache so the feed step
    /// shows real photos the moment it's swiped to. Any failure keeps the
    /// drawn samples — onboarding never shows an error for this.
    func load() async {
        guard !loaded, !loading,
              let url = URL(string: AppConfig.baseURL + "/public/showcase") else { return }
        loading = true
        defer { loading = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let decoded = try JSONDecoder().decode(Response.self, from: data).photos
            loaded = true
            // The rotation's photos. All of them still in the bundle (or
            // the showcase turned off): keep the bundled copies, no swap.
            let picks = Array(decoded.prefix(5))
            let bundledIds = Set(ShowcasePhoto.bundled.map(\.post_id))
            guard !picks.isEmpty, !picks.allSatisfy({ bundledIds.contains($0.post_id) }) else { return }
            // New picks: download first, then swap, so nothing flashes empty.
            for photo in picks {
                if let imageURL = photo.imageURL {
                    _ = try? await URLSession.shared.data(from: imageURL)
                }
            }
            photos = picks
        } catch {
            // Bundled photos stay.
        }
    }
}

#Preview {
    OnboardingIntroView(showsSignInLink: true) {}
}
