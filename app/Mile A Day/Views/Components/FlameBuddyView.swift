import SwiftUI

struct FlameBuddyView: View {
    let health: FlameHealth
    var size: CGFloat = 170
    var showsFace: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previousHealth: FlameHealth?
    @State private var burst = false

    var body: some View {
        ZStack {
            if reduceMotion {
                FlameBuddyFigure(health: health, flickerPhase: 0, blink: false, size: size, showsFace: showsFace)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let phase = CGFloat(t * 5.5)
                    let blink = Int(t * 2.0) % 9 == 0
                    FlameBuddyFigure(
                        health: health,
                        flickerPhase: phase,
                        blink: blink,
                        size: size,
                        showsFace: showsFace
                    )
                    .offset(y: sin(CGFloat(t) * 1.5) * 2.2)
                    .scaleEffect(burst ? 1.025 : 1)
                }
            }

            if burst {
                FlameBuddyBurst()
                    .frame(width: size * 1.25, height: size * 1.25)
                    .transition(.opacity)
            }
        }
        .onAppear {
            previousHealth = health
        }
        .onChange(of: health) { oldValue, newValue in
            previousHealth = oldValue
            guard newValue == .blazing, oldValue != .blazing else { return }
            MADHaptics.success()
            withAnimation(.easeOut(duration: 0.20)) {
                burst = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
                withAnimation(.easeOut(duration: 0.30)) {
                    burst = false
                }
            }
        }
    }
}

private struct FlameBuddyBurst: View {
    private let angles = Array(stride(from: 0.0, to: 360.0, by: 45.0))

    var body: some View {
        ZStack {
            ForEach(Array(angles.enumerated()), id: \.offset) { index, angle in
                Capsule()
                    .fill(index.isMultiple(of: 2) ? Color.orange.opacity(0.85) : Color.yellow.opacity(0.70))
                    .frame(width: 3, height: 12)
                    .offset(y: -sizeRelativeOffset)
                    .rotationEffect(.degrees(angle))
                    .opacity(0.62)
            }
        }
    }

    private var sizeRelativeOffset: CGFloat { 52 }
}
