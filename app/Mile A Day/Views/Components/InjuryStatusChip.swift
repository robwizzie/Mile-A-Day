import SwiftUI

/// "INJURED" beside a name, so friends can see why a streak has stopped moving.
///
/// Built to be safe next to a USERNAME, which is data: it must never carry
/// `.fixedSize()`. That publishes a minimum width no ancestor can shrink, and a
/// chip beside a name is exactly the shape that overflowed the collab header —
/// the row demanded more width than the screen had, the ScrollView centred and
/// clipped it, and the symptom was the screen gutter disappearing on a view
/// whose padding was provably correct.
///
/// Callers pair it with the name inside a `ViewThatFits` so a long username
/// wraps the chip to a second line instead of forcing the row wider. See
/// `InjuryNameRow`.
struct InjuryStatusChip: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 2 : 3) {
            Image(systemName: "pause.fill")
                .font(.system(size: compact ? 7 : 8, weight: .black))
            if !compact {
                Text("INJURED")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .tracking(0.3)
            }
        }
        .foregroundStyle(MADTheme.Colors.warning)
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, compact ? 2 : 2.5)
        .background(
            Capsule().fill(MADTheme.Colors.warning.opacity(0.18))
        )
        .accessibilityLabel("Paused for injury")
    }
}

/// A name with the injury chip beside it that degrades gracefully.
///
/// The two candidates differ only in ARRANGEMENT — same content, same chip. A
/// `ViewThatFits` whose branches differ in CONTENT silently deletes something
/// when the prediction is wrong, which is far worse than a tighter layout.
struct InjuryNameRow: View {
    let name: String
    var isInjured: Bool
    var font: Font = .system(size: 13.5, weight: .semibold)

    var body: some View {
        if isInjured {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    Text(name).font(font).lineLimit(1)
                    InjuryStatusChip()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(font).lineLimit(1)
                    InjuryStatusChip()
                }
            }
        } else {
            Text(name).font(font).lineLimit(1)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        InjuryNameRow(name: "robwizzie", isInjured: true)
        InjuryNameRow(name: "a_really_long_username_here", isInjured: true)
            .frame(width: 160)
        InjuryStatusChip(compact: true)
    }
    .padding()
    .background(Color(red: 0.10, green: 0.10, blue: 0.10))
    .foregroundStyle(.white)
}
