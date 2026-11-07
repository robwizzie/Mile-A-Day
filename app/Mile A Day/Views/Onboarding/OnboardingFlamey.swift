import SwiftUI

/// Flamey during setup. Each step gives him something to wear, each answer
/// adds to it, and `reaction` going up makes him hop, with a line about what
/// just happened. This is a preview on this screen only: it unlocks nothing,
/// and his real look still comes from the Closet.
struct OnboardingFlamey: View {
    /// Skin ids, later ones winning a slot. An unknown id is skipped.
    let items: [String]
    let size: CGFloat
    var line: String? = nil
    var reaction: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.introArtWidth) private var artWidth
    @State private var sparksOut = false

    private struct Hop {
        var lift: CGFloat = 0
        var stretch: CGFloat = 1
        var tilt: Double = 0
    }

    private var look: FlameyLook {
        var look = FlameyLook()
        for id in items {
            if let item = FlameyItem(rawValue: id) { look.wear(item) }
        }
        return look
    }

    var body: some View {
        ZStack {
            if !reduceMotion { sparks }
            FlameBuddyView(health: .blazing, size: size, showsMoodBubble: false, look: look)
                .frame(width: size, height: size)
                .keyframeAnimator(initialValue: Hop(), trigger: reduceMotion ? 0 : reaction) { content, hop in
                    content
                        .scaleEffect(x: 2 - hop.stretch, y: hop.stretch, anchor: .bottom)
                        .rotationEffect(.degrees(hop.tilt), anchor: .bottom)
                        .offset(y: hop.lift)
                } keyframes: { _ in
                    KeyframeTrack(\.stretch) {
                        CubicKeyframe(0.86, duration: 0.09)
                        SpringKeyframe(1.1, duration: 0.16)
                        SpringKeyframe(1, duration: 0.3)
                    }
                    KeyframeTrack(\.lift) {
                        LinearKeyframe(0, duration: 0.09)
                        SpringKeyframe(-size * 0.16, duration: 0.16)
                        SpringKeyframe(0, duration: 0.28)
                    }
                    KeyframeTrack(\.tilt) {
                        LinearKeyframe(0, duration: 0.09)
                        CubicKeyframe(-5, duration: 0.12)
                        CubicKeyframe(4, duration: 0.14)
                        CubicKeyframe(0, duration: 0.14)
                    }
                }
            if let line {
                IntroChip(text: line)
                    .id(line)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .offset(x: introClampX(size * 0.72, line, width: artWidth), y: -size * 0.3)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: line)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: reaction) {
            MADHaptics.tap()
            guard !reduceMotion else { return }
            sparksOut = false
            withAnimation(.easeOut(duration: 0.6)) { sparksOut = true }
        }
    }

    private var sparks: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) / 8 * 2 * .pi
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 5, height: 5)
                    .offset(x: sparksOut ? cos(angle) * size * 0.7 : 0,
                            y: sparksOut ? sin(angle) * size * 0.6 : 0)
                    .opacity(sparksOut ? 0 : (reaction > 0 ? 1 : 0))
            }
        }
        .accessibilityHidden(true)
    }
}
