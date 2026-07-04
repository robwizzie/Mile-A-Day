import SwiftUI

/// Shared hype affordances so every surface — the Notifications inbox, the
/// Friends "Today" feed, and anywhere else — speaks the same visual language.
///
/// Canonical hype glyph is `hands.clap` (👏). The actionable button is solid
/// orange; once spent it fades to a quiet grey "Hyped" chip.

// MARK: - Hype Button

/// One-shot "Hype" action button. Solid-orange while actionable, faded once the
/// viewer has hyped, and a muted disabled chip when the daily allowance is gone.
struct HypeButton: View {
    let isHyped: Bool
    var isBusy: Bool = false
    /// Daily hype allowance is spent and this workout isn't hyped yet.
    var isOutOfHypes: Bool = false
    let action: () -> Void

    @State private var pop = false

    private var actionable: Bool { !isHyped && !isBusy && !isOutOfHypes }

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
            HStack(spacing: 4) {
                Image(systemName: isHyped ? "hands.clap.fill" : "hands.clap")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(isHyped ? 0.55 : 1)
                    .scaleEffect(pop ? 1.4 : 1)
                Text(isHyped ? "Hyped" : "Hype")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundColor(foreground)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(background)
            .opacity(isBusy ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!actionable)
    }

    private var foreground: Color {
        if isHyped { return .white.opacity(0.35) }
        if isOutOfHypes { return .white.opacity(0.3) }
        return .white
    }

    @ViewBuilder private var background: some View {
        if isHyped {
            Capsule().fill(Color.white.opacity(0.06))
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
                .font(.system(size: showsLabel ? 12 : 10, weight: .bold))
                .foregroundColor(.orange)
            if showsLabel {
                Text("\(count) hype\(count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
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

// MARK: - Hypes-Remaining Pill

/// Shows how many hypes the user has left today. `compact` ("N left") fits the
/// navigation toolbar; the default descriptive form suits inline placement.
/// Dims to grey once the daily allowance is spent. Unlimited (admin/founder)
/// users get an "∞" pill that never depletes.
struct HypePill: View {
    let remaining: Int
    var compact: Bool = false
    /// The user's role bypasses the daily hype cap.
    var unlimited: Bool = false

    private var depleted: Bool { !unlimited && remaining <= 0 }
    private var tint: Color { depleted ? .white.opacity(0.55) : .orange }

    private var label: String {
        if unlimited { return compact ? "∞" : "Unlimited hypes" }
        if compact { return "\(remaining) left" }
        return "\(remaining) hype\(remaining == 1 ? "" : "s") left today"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "hands.clap.fill")
                .font(.system(size: 11, weight: .bold))
            Text(label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .fixedSize()
        .foregroundColor(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(pillBackground)
    }

    private var pillBackground: some View {
        Capsule()
            .fill(depleted ? Color.white.opacity(0.08) : Color.orange.opacity(0.15))
            .overlay(
                Capsule().strokeBorder(
                    depleted ? Color.white.opacity(0.18) : Color.orange.opacity(0.35),
                    lineWidth: 1
                )
            )
    }
}
