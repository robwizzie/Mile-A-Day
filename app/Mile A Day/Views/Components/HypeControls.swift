import SwiftUI

/// Shared hype affordances so every surface — the Notifications inbox, the
/// Friends "Today" feed, and anywhere else — speaks the same visual language.
///
/// Canonical hype glyph is `hands.clap` (👏). The actionable button is solid
/// orange; once spent it fades to a quiet grey "Hyped" chip.

// MARK: - Hype Button

enum HypeButtonStyle: Equatable {
    case pill
    /// The pill, sized for a dense list row.
    ///
    /// The Notifications inbox row already carries an avatar, a title, a
    /// three-line body and a trailing post thumbnail; the full-size pill
    /// competed with all of it and read as the loudest thing in a row whose
    /// subject is somebody ELSE's action. Same shape and colour — this is
    /// still the one hype language — just quieter.
    case smallPill
    case actionIcon
    /// The redesigned post card's footer glyph: smaller than `actionIcon`,
    /// sized to sit beside a count.
    case compactIcon
}

/// Instagram-style hype toggle. Feed cards use the large action icon, while
/// tighter rows can keep the labeled pill.
struct HypeButton: View {
    let isHyped: Bool
    var isBusy: Bool = false
    /// Daily hype allowance is spent and this workout isn't hyped yet.
    var isOutOfHypes: Bool = false
    var style: HypeButtonStyle = .pill
    let action: () -> Void

    @State private var pop = false

    private var actionable: Bool { !isBusy && (isHyped || !isOutOfHypes) }

    var body: some View {
        Button {
            guard actionable else { return }
            // Quick clap "pop" for a bit of tactile delight on tap.
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { pop = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pop = false }
            }
            action()
        } label: {
            Group {
                if style == .actionIcon {
                    Image(systemName: isHyped ? "hands.clap.fill" : "hands.clap")
                        .font(.system(size: 31, weight: .regular))
                        .scaleEffect(pop ? 1.16 : 1)
                        .opacity(isOutOfHypes && !isHyped ? 0.35 : 1)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                } else if style == .compactIcon {
                    Image(systemName: isHyped ? "hands.clap.fill" : "hands.clap")
                        .font(.system(size: 22, weight: .medium))
                        .scaleEffect(pop ? 1.18 : 1)
                        .opacity(isOutOfHypes && !isHyped ? 0.35 : 1)
                        .frame(width: 36, height: 40)
                        .contentShape(Rectangle())
                } else {
                    let small = style == .smallPill
                    let pill = HStack(spacing: small ? 4 : 5) {
                        Image(systemName: isHyped ? "hands.clap.fill" : "hands.clap")
                            .font(.system(size: small ? 13 : 17, weight: .bold))
                            .scaleEffect(pop ? 1.2 : 1)
                        Text(isHyped ? "Hyped" : "Hype")
                            .font(.system(size: small ? 12 : 14, weight: .heavy, design: .rounded))
                    }
                    .padding(.horizontal, small ? 11 : 15)
                    .padding(.vertical, small ? 6 : 9)
                    .background(background)
                    if small {
                        // The pill shrinks; the TARGET doesn't. A ~26pt control
                        // in a scrolling list is a miss waiting to happen, so
                        // the hit area is padded back out around the pill and
                        // made a rectangle. That padding is real layout — it
                        // takes the frame back to roughly the full pill's size
                        // — but it sits OUTSIDE `background`, so what the eye
                        // reads is the smaller pill and what the thumb gets is
                        // still ~38pt. Only this branch: `.pill` ships in the
                        // friends list and keeps its exact hit shape.
                        pill.padding(5).contentShape(Rectangle())
                    } else {
                        pill
                    }
                }
            }
            .foregroundColor(foreground)
            .opacity(isBusy ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!actionable)
    }

    private var foreground: Color {
        if isHyped { return .orange }
        if isOutOfHypes { return .white.opacity(0.3) }
        return .white
    }

    @ViewBuilder private var background: some View {
        if isHyped {
            Capsule()
                .fill(Color.orange.opacity(0.12))
                .overlay(Capsule().strokeBorder(Color.orange.opacity(0.45), lineWidth: 1))
        } else if isOutOfHypes {
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        } else {
            Capsule()
                .fill(Color.orange)
                .shadow(color: Color.orange.opacity(0.35), radius: 5, y: 2)
        }
    }
}

// MARK: - Hype Tally

/// Social-proof badge: how many hypes a single workout/event has received.
/// Compact form reads "👏 N" (tight rows); labeled form reads "👏 3 hypes"
/// — the Instagram-likes-style line used on feed cards, where it's also the
/// tap target for "who hyped this".
struct HypeTally: View {
    let count: Int
    /// Render the spelled-out "N hypes" form (feed cards).
    var showsLabel: Bool = false

    var body: some View {
        HStack(spacing: showsLabel ? 5 : 3) {
            Image(systemName: "hands.clap.fill")
                .font(.system(size: showsLabel ? 18 : 13, weight: .semibold))
                .foregroundColor(.orange)
            if showsLabel {
                Text("\(count) hype\(count == 1 ? "" : "s")")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.9))
            } else {
                Text("\(count)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.orange)
            }
        }
    }
}
