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
            let artHeight = max(160, heroHeight - topInset - curve - iconSize / 2 - 12)

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
                            topInset: topInset,
                            textTop: heroHeight + iconSize / 2 + 18,
                            photos: showcase.photos
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
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
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: iconSize * 0.24 + 5, style: .continuous)
                    .fill(Self.sheetColor)
            )
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
    enum Art { case welcome, flamey, feed, friends, rewards }

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
    let topInset: CGFloat
    let textTop: CGFloat
    let photos: [ShowcasePhoto]

    /// Pops once, the first time this step is on screen.
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .top) {
            art
                .frame(maxWidth: .infinity)
                .frame(height: artHeight)
                .padding(.top, topInset + 8)
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
        case .feed: IntroFeedArt(height: artHeight, photos: photos)
        case .friends: IntroFriendsArt(height: artHeight)
        case .rewards: IntroRewardsArt(height: artHeight)
        }
    }
}

// MARK: - Shared art pieces

private struct IntroShownKey: EnvironmentKey { static let defaultValue = true }
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
                .offset(x: -flame * 0.62, y: -flame * 0.42)
            IntroChip(text: "✓ " + introMiles(1.02) + " today", tint: Color(red: 0.15, green: 0.55, blue: 0.3))
                .introBob(6, period: 3.4, phase: 0.6)
                .introPop(0.35)
                .offset(x: flame * 0.58, y: flame * 0.40)
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

// MARK: - Step 3: feed photos

private struct IntroFeedArt: View {
    let height: CGFloat
    let photos: [ShowcasePhoto]

    var body: some View {
        let width = min(height * 0.52, 190)
        ZStack {
            card(2, width: width * 0.86)
                .rotationEffect(.degrees(9))
                .offset(x: width * 0.66, y: 14)
                .introPop(0.2)
            card(1, width: width * 0.86)
                .rotationEffect(.degrees(-9))
                .offset(x: -width * 0.66, y: 14)
                .introPop(0.12)
            // The front one is a real feed post: who, their streak, the
            // photo, the caption and the hype button, like in the app.
            IntroFeedPost(photo: photos.first, height: height)
                .introPop(0)
                .introBob(4, period: 3.6)

            // Lower left, over the side print: clear of Skip and the post.
            IntroChip(text: "🔥 Hyped by 12")
                .introBob(6, period: 3.0, phase: 0.4)
                .introPop(0.35)
                .offset(x: -width * 0.72, y: width * 0.52)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(_ slot: Int, width: CGFloat) -> some View {
        IntroPhotoCard(photo: photos.indices.contains(slot) ? photos[slot] : nil, slot: slot, width: width)
    }
}

/// A feed photo as a tilted print. Real showcase photo when loaded, a drawn
/// sample otherwise (signed-out devices, offline, or the showcase turned off).
private struct IntroPhotoCard: View {
    let photo: ShowcasePhoto?
    let slot: Int
    let width: CGFloat

    private static let samples: [(name: String, miles: Double, colors: [Color])] = [
        ("maya", 1.04, [Color(red: 0.98, green: 0.62, blue: 0.35), Color(red: 0.85, green: 0.28, blue: 0.36)]),
        ("jay", 1.21, [Color(red: 0.36, green: 0.62, blue: 0.95), Color(red: 0.25, green: 0.30, blue: 0.62)]),
        ("sam", 2.03, [Color(red: 0.40, green: 0.78, blue: 0.52), Color(red: 0.16, green: 0.45, blue: 0.40)])
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
        if let url = photo?.imageURL {
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

/// A feed post in miniature, from a real showcase photo (drawn sample when
/// none loaded): avatar + name + streak, the photo, caption and hype row.
private struct IntroFeedPost: View {
    let photo: ShowcasePhoto?
    let height: CGFloat

    var body: some View {
        // Width first (a card that reads as a post), photo fills what's left.
        let width = min(height * 0.82, 200)
        let photoHeight = max(70, min(width * 1.1, height - 80))
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                avatar
                Text(photo?.username ?? "maya")
                    .madFont(size: 13, weight: .bold, design: .rounded, maxScale: 1.1)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let streak = streakShown {
                    Text("🔥 \(streak)")
                        .madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1.1)
                        .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.25))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 40)

            IntroPhotoCard.photoFace(photo: photo, slot: 0, width: width, height: photoHeight)

            HStack(spacing: 6) {
                Text("🔥 Hype")
                    .madFont(size: 12, weight: .bold, design: .rounded, maxScale: 1.1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(MADTheme.Colors.madRed))
                Text(photo?.caption ?? "Sunset mile 🌅")
                    .madFont(size: 12, weight: .medium, design: .rounded, maxScale: 1.1)
                    .opacity(0.8)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
        }
        .foregroundColor(.white)
        .frame(width: width)
        .background(Color(red: 0.10, green: 0.07, blue: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        .accessibilityHidden(true)
    }

    /// The real post's streak; the sample's when nothing loaded.
    private var streakShown: Int? {
        guard let photo else { return 128 }
        return photo.streak
    }

    @ViewBuilder
    private var avatar: some View {
        let fallback = Circle().fill(MADTheme.Colors.madRed)
            .overlay(Text(String((photo?.username ?? "m").prefix(1)).uppercased())
                .madFont(size: 12, weight: .heavy, design: .rounded, maxScale: 1))
        Group {
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
        .frame(width: 24, height: 24)
        .clipShape(Circle())
    }
}

// MARK: - Step 4: friends (a Today board in miniature)

private struct IntroFriendsArt: View {
    let height: CGFloat

    var body: some View {
        let tile = min((height - 60) * 0.62, 112)
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                IntroFriendTile(initial: "M", name: "Maya", kind: .done, size: tile)
                    .introPop(0)
                IntroFriendTile(initial: "J", name: "Jay", kind: .nudge, size: tile)
                    .introPop(0.1)
                    .introBob(4, period: 2.8)
                IntroFriendTile(initial: "S", name: "Sam", kind: .walking, size: tile)
                    .introPop(0.2)
            }
            IntroChip(text: "👋 You nudged Jay · 1h 40m left")
                .introPop(0.35)
                .introBob(4, period: 3.4, phase: 0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct IntroFriendTile: View {
    enum Kind { case done, nudge, walking }
    let initial: String
    let name: String
    let kind: Kind
    let size: CGFloat

    private var ring: Color {
        switch kind {
        case .done: return Color(red: 0.30, green: 0.82, blue: 0.48)
        case .nudge: return MADTheme.Colors.madRed
        case .walking: return MADTheme.Colors.walkBlue
        }
    }

    private var label: String {
        switch kind {
        case .done: return "Done ✓"
        case .nudge: return "Nudge"
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
                Text(initial)
                    .madFont(size: size * 0.24, weight: .heavy, design: .rounded, maxScale: 1)
                    .foregroundColor(.white)
            }
            .frame(width: size * 0.52, height: size * 0.52)
            .padding(.top, size * 0.14)

            Text(name)
                .madFont(size: 13, weight: .semibold, design: .rounded, maxScale: 1.1)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .padding(.top, 6)

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

// MARK: - Step 5: competitions, medals, Flamey's closet

private struct IntroRewardsArt: View {
    let height: CGFloat

    var body: some View {
        let flame = min(height * 0.6, 220)
        ZStack {
            IntroOutfitCycler(size: flame)
                .introPop(0.05)
                .introBob(4, period: 3.6)

            IntroChip(text: "🏆 Won the weekend duel")
                .introBob(5, period: 3.0, phase: 0.1)
                .introPop(0.2)
                .offset(x: -flame * 0.5, y: -flame * 0.5)
            IntroChip(text: "🏅 100 miles")
                .introBob(5, period: 3.3, phase: 0.5)
                .introPop(0.3)
                .offset(x: flame * 0.7, y: -flame * 0.05)
            IntroChip(text: "❄️ January flame")
                .introBob(5, period: 3.6, phase: 0.8)
                .introPop(0.4)
                .offset(x: -flame * 0.55, y: flame * 0.42)
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

    var id: String { post_id }
    var imageURL: URL? { ProfileImageService.fullImageURL(for: media_url) }
    var avatarURL: URL? { ProfileImageService.fullImageURL(for: profile_image_url) }
}

@MainActor
final class ShowcasePhotoStore: ObservableObject {
    static let shared = ShowcasePhotoStore()

    @Published private(set) var photos: [ShowcasePhoto] = []
    private var loading = false

    private struct Response: Decodable { let photos: [ShowcasePhoto] }

    /// Fetch once per launch, then warm the image cache so the feed step
    /// shows real photos the moment it's swiped to. Any failure keeps the
    /// drawn samples — onboarding never shows an error for this.
    func load() async {
        guard photos.isEmpty, !loading,
              let url = URL(string: AppConfig.baseURL + "/public/showcase") else { return }
        loading = true
        defer { loading = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let decoded = try JSONDecoder().decode(Response.self, from: data).photos
            photos = Array(decoded.prefix(3))  // front post + two prints
            for photo in photos {
                if let imageURL = photo.imageURL {
                    _ = try? await URLSession.shared.data(from: imageURL)
                }
            }
        } catch {
            // Drawn samples stay.
        }
    }
}

#Preview {
    OnboardingIntroView(showsSignInLink: true) {}
}
