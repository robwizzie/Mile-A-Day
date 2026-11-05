import SwiftUI

/// Live guided tour over the real app. Each step switches to its tab, dims
/// the app and cuts a spotlight around the real element it's explaining
/// (`.tourAnchor(_:)` reports where that element is), with one short card on
/// the other half of the screen. The spotlight glides between elements.
///
/// Smoothness rules (the first two versions felt laggy):
/// - No material blur: it re-samples the live tabs behind it every frame.
/// - A tap answers at once (the card's text fades out), the tab switches
///   while nothing is animating, and the spotlight + new text arrive only
///   once the new screen has reported its element (or after a short cap).
///   A tab's first build is main-thread work; doing it mid-animation is what
///   made Next feel sticky.
struct AppGuidedTourView: View {
    /// Stamped when the tour ends (Done or Skip) — the dashboard's
    /// getting-started checklist reads it.
    static let seenKey = "hasSeenAppGuidedTour"

    let onComplete: () -> Void

    @ObservedObject private var anchors = TourAnchors.shared
    @State private var step = 0
    @State private var textVisible = false
    @State private var shown = false
    @State private var busy = false

    private let steps = GuidedTourStep.all
    private var isLast: Bool { step >= steps.count - 1 }
    private var current: GuidedTourStep { steps[step] }

    private static let surface = Color(red: 0.09, green: 0.06, blue: 0.075)

    var body: some View {
        // The OUTER reader respects the safe area, so its insets are real
        // (one that ignores the safe area reads them as zero, which put a top
        // card under the status bar); the content then fills the screen.
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let size = CGSize(width: geo.size.width + insets.leading + insets.trailing,
                              height: geo.size.height + insets.top + insets.bottom)
            let frame = geo.frame(in: .global)
            let origin = CGPoint(x: frame.minX - insets.leading, y: frame.minY - insets.top)
            let hole = spotlight(in: size, origin: origin)
            let cardOnTop = hole.map { $0.midY > size.height * 0.5 } ?? false

            ZStack {
                // Dim everything except the spotlight; absorbs taps on the app.
                SpotlightShape(hole: hole ?? CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0),
                               radius: 18)
                    .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
                    .contentShape(Rectangle())
                    .onTapGesture { }

                if let hole {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(current.accent.opacity(0.9), lineWidth: 2)
                        .frame(width: hole.width, height: hole.height)
                        .position(x: hole.midX, y: hole.midY)
                        .allowsHitTesting(false)
                }

                VStack(spacing: 0) {
                    if !cardOnTop { Spacer(minLength: 0) }
                    card
                        .padding(.horizontal, 16)
                        .padding(.top, cardOnTop ? insets.top + 8 : 0)
                        // Clear the tab bar (~49pt) above the home indicator.
                        .padding(.bottom, cardOnTop ? 0 : insets.bottom + 62)
                    if cardOnTop { Spacer(minLength: 0) }
                }
            }
            .frame(width: size.width, height: size.height)
            .offset(x: -insets.leading, y: -insets.top)
            .opacity(shown ? 1 : 0)
        }
        // Only a step change animates; anchor reports apply as they come.
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: step)
        .onAppear(perform: start)
        .onDisappear { anchors.isRecording = false }
    }

    /// The current step's element, in this view's coordinates, padded.
    private func spotlight(in size: CGSize, origin: CGPoint) -> CGRect? {
        guard let id = current.anchor, let frame = anchors.frames[id], frame.width > 0 else { return nil }
        let local = frame.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -8, dy: -8)
        // Keep it on screen (a tall element is clipped to the visible part);
        // scrolled off, or only a sliver showing, means no spotlight.
        let visible = local.intersection(CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4))
        guard !visible.isNull, visible.height >= 32, visible.width >= 32 else { return nil }
        return visible
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(current.tabName, systemImage: current.icon)
                    .madFont(size: 13, weight: .bold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(current.accent)
                Text("· \(step + 1) of \(steps.count)")
                    .madFont(size: 13, weight: .semibold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.45))
                Spacer()
                Button("Skip", action: finish)
                    .madFont(size: 14, weight: .semibold, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.55))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(current.title)
                    .madFont(size: 21, weight: .heavy, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white)
                Text(current.body)
                    .madFont(size: 15, weight: .medium, design: .rounded, maxScale: 1.3)
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(step)
            .transition(.opacity)
            .opacity(textVisible ? 1 : 0)

            HStack(spacing: 12) {
                if step > 0 {
                    Button("Back") { go(to: step - 1) }
                        .madFont(size: 15, weight: .semibold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white.opacity(0.7))
                }
                HStack(spacing: 5) {
                    ForEach(steps.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == step ? current.accent : Color.white.opacity(0.2))
                            .frame(width: i == step ? 16 : 5, height: 5)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(step + 1) of \(steps.count)")

                Button {
                    if isLast { finish() } else { go(to: step + 1) }
                } label: {
                    Text(isLast ? "Done" : "Next")
                        .madFont(size: 15, weight: .bold, design: .rounded, maxScale: 1.3)
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(MADTheme.Colors.madRed))
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Self.surface))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.06), lineWidth: 1))
        .disabled(busy)
    }

    // MARK: - Flow

    private func start() {
        anchors.isRecording = true
        switchToTab(steps[0].tabIndex)
        settle(on: 0) {
            withAnimation(.easeOut(duration: 0.25)) { shown = true }
        }
    }

    /// Same tab: the spotlight and text move at once, on the tap.
    /// New tab: the text fades at once (feedback), the tab switches right
    /// away, and the spotlight + text arrive as soon as the new screen has
    /// reported its element (0.5s cap) — never mid-build.
    private func go(to newStep: Int) {
        guard !busy else { return }
        MADHaptics.tap()
        guard steps[newStep].tabIndex != current.tabIndex else {
            step = newStep
            return
        }
        busy = true
        withAnimation(.easeOut(duration: 0.1)) { textVisible = false }
        switchToTab(steps[newStep].tabIndex)
        settle(on: newStep) { busy = false }
    }

    /// Wait (up to 0.5s) for the step's element to report, then show it.
    private func settle(on newStep: Int, then done: @escaping () -> Void) {
        let target = steps[newStep].anchor
        let deadline = Date().addingTimeInterval(0.5)
        func check() {
            let ready = target.map { (anchors.frames[$0]?.width ?? 0) > 0 } ?? true
            if ready || Date() >= deadline {
                step = newStep
                withAnimation(.easeOut(duration: 0.18)) { textVisible = true }
                done()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { check() }
            }
        }
        // One run loop first so the tab switch lands before we look.
        DispatchQueue.main.async { check() }
    }

    private func finish() {
        switchToTab(0)
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        withAnimation(.easeOut(duration: 0.2)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            anchors.isRecording = false
            onComplete()
        }
    }

    private func switchToTab(_ tab: Int) {
        NotificationCenter.default.post(
            name: NSNotification.Name("MAD_SwitchTab"),
            object: nil,
            userInfo: ["tab": tab]
        )
    }
}

// MARK: - Spotlight

/// The dim layer with a rounded hole; the hole animates between elements.
private struct SpotlightShape: Shape {
    var hole: CGRect
    var radius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.minX, hole.minY), AnimatablePair(hole.width, hole.height)) }
        set {
            hole = CGRect(x: newValue.first.first, y: newValue.first.second,
                          width: newValue.second.first, height: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if hole.width > 0, hole.height > 0 {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        }
        return path
    }
}

// MARK: - Anchors

/// Where the tour's target elements are on screen, in global coordinates.
/// Recorded only while a tour is running, so normal scrolling pays nothing.
@MainActor
final class TourAnchors: ObservableObject {
    static let shared = TourAnchors()

    /// Frames by id. Not @Published itself: `version` bumps (debounced by
    /// value) so the tour redraws without every reporter observing.
    private(set) var frames: [String: CGRect] = [:]
    @Published private(set) var version = 0
    /// Reporters already on screen re-report when a tour starts.
    @Published var isRecording = false

    func report(_ id: String, frame: CGRect) {
        guard isRecording, frames[id] != frame else { return }
        frames[id] = frame
        version &+= 1
    }
}

private struct TourAnchorReporter: View {
    let id: String
    @ObservedObject private var anchors = TourAnchors.shared

    var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            Color.clear
                .onAppear { anchors.report(id, frame: frame) }
                .onChange(of: frame) { _, newFrame in anchors.report(id, frame: newFrame) }
                .onChange(of: anchors.isRecording) { _, recording in
                    if recording { anchors.report(id, frame: frame) }
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Marks this view as a stop on the guided tour (`GuidedTourStep.anchor`).
    func tourAnchor(_ id: String) -> some View {
        background(TourAnchorReporter(id: id))
    }
}

// MARK: - Tour Step Data

private struct GuidedTourStep {
    let tabName: String
    let icon: String
    let tabIndex: Int
    /// The `.tourAnchor` id to spotlight; nil = no spotlight (card only).
    let anchor: String?
    let title: String
    let body: String
    let accent: Color

    static let all: [GuidedTourStep] = [
        GuidedTourStep(tabName: "Dashboard", icon: "house.fill", tabIndex: 0, anchor: "home.hero",
                       title: "This is Flamey",
                       body: "He's your streak. Do a mile every day to keep him lit. He shrinks as the day goes if you haven't.",
                       accent: .orange),
        GuidedTourStep(tabName: "Dashboard", icon: "house.fill", tabIndex: 0, anchor: "home.start",
                       title: "Track your mile",
                       body: "Tap Start to track a walk or run. Walks from Apple Health or your Watch count on their own too.",
                       accent: MADTheme.Colors.madRed),
        GuidedTourStep(tabName: "Dashboard", icon: "house.fill", tabIndex: 0, anchor: "home.header",
                       title: "Alerts and settings",
                       body: "The bell has your notifications. The gear opens Settings.",
                       accent: MADTheme.Colors.madRed),
        GuidedTourStep(tabName: "Compete", icon: "trophy.fill", tabIndex: 1, anchor: "compete.header",
                       title: "Race your friends",
                       body: "Tap + to start a competition over days or weeks.",
                       accent: .orange),
        GuidedTourStep(tabName: "Feed", icon: "square.stack.fill", tabIndex: 2, anchor: "feed.board",
                       title: "Who's done today",
                       body: "Everyone's day at a glance. Tap a friend to watch their story, hype them, or nudge them.",
                       accent: MADTheme.Colors.walkBlue),
        GuidedTourStep(tabName: "Feed", icon: "square.stack.fill", tabIndex: 2, anchor: nil,
                       title: "Show off your walk",
                       body: "Post a photo after your mile. Tap the clap on a friend's post to hype it.",
                       accent: MADTheme.Colors.walkBlue),
        GuidedTourStep(tabName: "Friends", icon: "person.2.fill", tabIndex: 3, anchor: "friends.header",
                       title: "Bring your friends",
                       body: "Tap Add friends to find people. Streaks are better together.",
                       accent: .cyan),
        GuidedTourStep(tabName: "Profile", icon: "person.fill", tabIndex: 4, anchor: "profile.hero",
                       title: "Your profile",
                       body: "Your streak, miles and medals. The gear up here opens Settings any time.",
                       accent: .purple)
    ]
}

#Preview {
    AppGuidedTourView { }
}
