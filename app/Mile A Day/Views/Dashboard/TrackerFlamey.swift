import SwiftUI

// Flamey on the workout tracker (Fun only). Two pieces, both extracted from
// WorkoutTrackingView — whose body is at the type-checker's limit — and both
// drawing NOTHING on Modern:
//
//  - `TrackerFlameyBuddy`: a small Flamey standing off the progress ring's
//    lower-right edge, as an OVERLAY on the ring (so the metric column's
//    GeometryReader-derived layout never moves). His energy follows the
//    DAY's progress, the same figure the ring fills with.
//  - `TrackerFlameyCheer`: the goal overlay's hero on Fun, in place of the
//    checkmark — so the cheer IS the existing celebration (same one-shot,
//    same 3 seconds), never a second overlay competing with it.

/// The day's progress → how he feels on the tracker.
enum TrackerFlameyMood {
    /// Calm while the day is young, bouncing mid-way, hyped (fast hop +
    /// sparkles) near the end, shades on once the goal is in.
    static func kind(for progress: Double) -> FlameMood.Kind {
        // Shared with the Workout Live Activity (FlameyMoodCore.swift).
        FlameMoodKind.forWorkoutProgress(progress)
    }
}

struct TrackerFlameyBuddy: View {
    /// The DAY's progress toward the goal, 0...1 (`totalDailyDistance / goal`).
    let progress: Double
    var size: CGFloat = 62

    @AppStorage(DashboardStylePreference.key) private var style = DashboardStyle.modern.rawValue

    var body: some View {
        if style == DashboardStyle.fun.rawValue {
            let kind = TrackerFlameyMood.kind(for: progress)
            FlameBuddyView(
                health: progress >= 1 ? .blazing : .healthy,
                size: size,
                mood: FlameMood(kind: kind, streak: 0),
                // A bubble at this size would sit on the ring's numbers; his
                // tempo and props carry the mood on their own.
                showsMoodBubble: false,
                // A small surface: colour, head, eyes, chest, feet —
                // standing on the ground (no jets over the ring).
                look: FlameyFacts.look(mood: kind, detail: .compact)
            )
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct CheerBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The goal overlay's centrepiece on Fun: Flamey in his party look, a spark
/// burst as it lands, confetti, and "You did it!" in his bubble.
struct TrackerFlameyCheer: View {
    var size: CGFloat = 150

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burstAt: Date?

    var body: some View {
        VStack(spacing: size * 0.10) {
            // His own bubble, stacked ABOVE him: the mood layer's bubble sits
            // on the tip, which is exactly where the party hat is.
            cheerBubble
            ZStack(alignment: .bottom) {
                FlameyStageGround()
                    .frame(width: size * 1.1, height: size * 0.12)
                    .offset(y: size * 0.03)
                ZStack {
                    FlameBuddyView(health: .blazing, size: size, mood: FlameMood(kind: .party, streak: 0),
                                   showsMoodBubble: false,
                                   look: FlameyFacts.look(mood: .party) ?? .plain)
                    if let burstAt {
                        FlameIgnitionBurst(startDate: burstAt, size: size)
                    }
                }
                .frame(width: size, height: size)
            }
            // Room for the hat over his tip (and his legs, when he's shod).
            .frame(width: size * 1.5, height: size * 1.45, alignment: .bottom)
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            burstAt = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + FlameIgnitionBurst.duration + 0.1) {
                burstAt = nil
            }
        }
    }

    /// Cream with dark lettering and a tail, like his dashboard bubble.
    private var cheerBubble: some View {
        let cream = Color(red: 1.0, green: 0.97, blue: 0.91)
        return VStack(spacing: -1) {
            Text("You did it!")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(Color(red: 0.24, green: 0.10, blue: 0.08))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cream))
            CheerBubbleTail()
                .fill(cream)
                .frame(width: 16, height: 9)
        }
        .rotationEffect(.degrees(-3))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    /// Fun right now — the tracker swaps its checkmark for him only then.
    static var isAvailable: Bool { DashboardStylePreference.current == .fun }
}
