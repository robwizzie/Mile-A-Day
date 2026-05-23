import SwiftUI

/// Avatar inside a circular progress ring. Replaces the inline progress bar
/// pattern used on friend rows — the ring color and a small status badge
/// communicate completion at a glance.
///
/// `progress` is clamped to [0, 1]. When `progress >= 1`, the ring renders as
/// a full solid green ring and a checkmark badge appears in the bottom-right.
struct AvatarWithRing: View {
    let name: String
    let imageURL: String?
    let progress: Double
    let size: CGFloat
    var ringWidth: CGFloat = 3
    /// Optional override for the in-progress ring color. Defaults to a warm
    /// orange→red gradient. When `progress >= 1` this is ignored in favor of
    /// solid green.
    var accent: Color = .orange
    /// Show a small badge in the bottom-right corner. `.check` for completed,
    /// `.live` for an active workout in progress, `nil` for none.
    var badge: Badge? = nil

    enum Badge {
        case check        // green checkmark — goal completed
        case live         // pulsing red dot — workout in progress
    }

    private var clamped: Double { max(0, min(1, progress)) }
    private var isComplete: Bool { clamped >= 1 }

    var body: some View {
        ZStack {
            // Faint base track — visible even at 0 progress so the ring shape
            // is always read as a ring, not an unframed avatar.
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: ringWidth)
                .frame(width: size, height: size)

            // Progress arc
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    isComplete
                        ? AnyShapeStyle(Color.green)
                        : AnyShapeStyle(
                            AngularGradient(
                                colors: [accent.opacity(0.55), accent, accent.opacity(0.85)],
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            )
                        ),
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size, height: size)
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: clamped)

            AvatarView(name: name, imageURL: imageURL, size: size - (ringWidth * 2) - 4)
        }
        .overlay(alignment: .bottomTrailing) {
            if let badge = badge {
                badgeView(badge)
                    // Tuck the badge so it overlaps the ring rather than
                    // ballooning the bounding box.
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func badgeView(_ badge: Badge) -> some View {
        switch badge {
        case .check:
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.22, weight: .heavy))
                .foregroundColor(.white)
                .frame(width: size * 0.32, height: size * 0.32)
                .background(Circle().fill(Color.green))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 1.5))
        case .live:
            ZStack {
                Circle()
                    .fill(MADTheme.Colors.madRed)
                    .frame(width: size * 0.30, height: size * 0.30)
                Circle()
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5)
                    .frame(width: size * 0.30, height: size * 0.30)
            }
        }
    }
}
