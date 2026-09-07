import SwiftUI

/// "🔥 136" — someone's streak, beside their name.
///
/// One construction because it had three, and the identical fragility in each:
/// the number carried no `lineLimit`, so in a squeezed row SwiftUI wrapped its
/// DIGITS. A 136-day streak rendered as "13" over "6" next to a name truncated
/// to "Aar…" — a number that reads as two numbers, in the row whose whole job
/// is to say how someone is doing.
///
/// Why a row gets squeezed at all: the friends list puts the name column beside
/// a "Donate a Mile · 2.00 mi further today" pill and a nudge button, and those
/// take what they need first. The name is the right thing to give up space —
/// it truncates, and a truncated name is still a name. A truncated number is a
/// different number, so this never yields.
///
/// `fixedSize` is safe HERE and would not be on the chips next to it: ios.md's
/// rule is that it must never wrap a label whose text is DATA, because it
/// publishes a minimum width no ancestor can shrink (the `WorkoutSourceChip`
/// case, where an app name falls back to a bundle-id leaf and demanded 487pt of
/// a 430pt screen). A streak is bounded — four digits is 10,000 consecutive
/// days — so the floor it publishes is ~40pt and cannot run away.
struct StreakFlameChip: View {
    let streak: Int
    /// The row chips are 10/11; the hero headline's is a size up.
    var glyphSize: CGFloat = 10
    var numberSize: CGFloat = 11
    var color: Color = .orange

    var body: some View {
        if streak > 0 {
            HStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(.system(size: glyphSize, weight: .bold))
                Text("\(streak)")
                    .font(.system(size: numberSize, weight: .heavy, design: .rounded))
                    // Monospaced so a streak ticking 99 → 100 doesn't shuffle
                    // the name beside it.
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundColor(color)
            .fixedSize(horizontal: true, vertical: false)
            // The flame reads as nothing and the number reads as a bare
            // integer, so neither says what this is on its own.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(streak) day streak")
        }
    }
}
