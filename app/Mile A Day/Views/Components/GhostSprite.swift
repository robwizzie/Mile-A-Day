import SwiftUI

/// The ghost you race, as an actual character.
///
/// Drawn rather than symbol-based on purpose. SF Symbols has no ghost that
/// exists on the iOS 17 deployment target — and a symbol that ships in a later
/// release renders as a BLANK box on 17, not a fallback. Drawing it also means
/// the ghost can act: bob, look back over its shoulder, and fade out when it
/// gets beaten, none of which a glyph can do.
///
/// Used everywhere the race is: the pre-start option card, the options step,
/// the live delta chip, the beaten celebration, and the feed chip.
struct GhostSprite: View {
    var size: CGFloat = 64
    /// Body fill. White reads on every surface the race appears on.
    var color: Color = .white
    /// Gentle vertical bob. Off for static contexts (chips, feed cards).
    var floats: Bool = true
    /// Eyes shifted back over its shoulder — for "you're gaining on it".
    var glancesBack: Bool = false
    /// Fades and drifts away, for the moment it's beaten.
    var isVanishing: Bool = false

    @State private var bob: CGFloat = 0

    private var eyeSize: CGFloat { size * 0.13 }

    var body: some View {
        ZStack {
            GhostBodyShape()
                .fill(color)

            // Eyes sit high on the body; the head is a semicircle of radius
            // size/2, so 0.36 keeps them clear of the crown and the hem.
            HStack(spacing: size * 0.16) {
                eye
                eye
            }
            .offset(
                x: glancesBack ? -size * 0.09 : 0,
                y: -size * 0.14
            )
        }
        .frame(width: size, height: size * 1.15)
        .offset(y: bob)
        .opacity(isVanishing ? 0 : 1)
        .scaleEffect(isVanishing ? 1.35 : 1)
        .blur(radius: isVanishing ? 6 : 0)
        .animation(.easeOut(duration: 0.9), value: isVanishing)
        .onAppear {
            guard floats else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                bob = -size * 0.06
            }
        }
    }

    private var eye: some View {
        Ellipse()
            .fill(Color.black.opacity(0.72))
            .frame(width: eyeSize, height: eyeSize * 1.25)
    }
}

/// Classic sheet-ghost silhouette: domed head, straight sides, wavy hem.
struct GhostBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let radius = w / 2
        // Hem amplitude. The baseline sits one amplitude above the bottom so
        // the downward humps land exactly on `h` and nothing clips.
        let amp = min(h * 0.06, w * 0.09)
        let base = h - amp

        var path = Path()
        path.move(to: CGPoint(x: 0, y: base))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addArc(
            center: CGPoint(x: radius, y: radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: w, y: base))

        // Hem, walked right→left. A quad curve between two points on the
        // baseline peaks at half its control offset, so ±2·amp controls give
        // humps of exactly ±amp.
        let humps = 4
        let segment = w / CGFloat(humps)
        for index in 0..<humps {
            let startX = w - CGFloat(index) * segment
            let endX = startX - segment
            let downward = index.isMultiple(of: 2)
            path.addQuadCurve(
                to: CGPoint(x: endX, y: base),
                control: CGPoint(
                    x: (startX + endX) / 2,
                    y: base + (downward ? 2 * amp : -2 * amp)
                )
            )
        }

        path.closeSubpath()
        return path
    }
}

/// Small ghost + time, for chips and rows. Sized to sit inline with text.
struct GhostTimePill: View {
    let seconds: Double
    var tint: Color = .white
    var background: Color = Color.white.opacity(0.15)

    var body: some View {
        HStack(spacing: 5) {
            GhostSprite(size: 12, color: tint, floats: false)
            Text(BestEffortStore.formatSeconds(seconds))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundColor(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(background))
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 40) {
            GhostSprite(size: 96)
            GhostSprite(size: 60, glancesBack: true)
            GhostTimePill(seconds: 542)
        }
    }
}
