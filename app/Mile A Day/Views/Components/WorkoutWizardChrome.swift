import SwiftUI

// The pre-start wizard's chrome, shared.
//
// These were private helpers inside `WorkoutTrackingView`, which meant the
// only screen that could look like the Start Mile flow WAS the Start Mile
// flow. Setting up a buddy walk had grown its own form — a modal sheet with a
// summary hero, segmented toggles and a 2x2 grid — so the moment someone
// tapped "With a Buddy" the app changed language on them. Extracting the
// chrome is what lets that setup be steps in the same scaffold: the same top
// bar, the same glyph-over-question header, the same option cards.
//
// Deliberately extracted as VIEWS rather than moved wholesale: the tracker's
// body is already at the type-checker's limit (ios.md), so its private helpers
// survive as one-line wrappers over these and none of its call sites move.

/// What a step puts above its question. The ghost is drawn, not a symbol —
/// SF Symbols has none that exists on the iOS 17 deployment target.
enum WizardGlyph {
    case symbol(String)
    case ghost
}

/// The gradient every wizard step sits on. The tracker paints these same four
/// stops inline in its own body; they live here too so a setup screen presented
/// OVER that body reads as the next step of it rather than a different app.
struct WizardBackground: View {
    static let top = Color(red: 0.85, green: 0.25, blue: 0.35)
    static let bottom = Color(red: 0.3, green: 0.1, blue: 0.15)

    var body: some View {
        LinearGradient(
            colors: [
                Self.top,
                Color(red: 0.7, green: 0.2, blue: 0.3),
                Color(red: 0.5, green: 0.15, blue: 0.2),
                Self.bottom
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// Back chevron + progress. Every pre-start step uses this so the screens read
/// as one flow rather than views that happen to share a gradient. `step` is
/// 1-based over three segments; a sub-step passes its parent's number.
struct WizardTopBar: View {
    let step: Int
    let onBack: () -> Void

    var body: some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Back")
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    // contentShape expands the hit target to the full padded
                    // bounds so the first tap registers even on the gaps
                    // between the icon glyph and the text.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(index <= step ? 0.9 : 0.25))
                        .frame(width: 22, height: 4)
                }
            }
            .allowsHitTesting(false)
        }
        .padding(.top, 16)
    }
}

/// Glyph + question, identical on every step.
struct WizardHeader: View {
    let glyph: WizardGlyph
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Group {
                switch glyph {
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: 52))
                case .ghost:
                    GhostSprite(size: 56, glancesBack: true)
                }
            }
            .foregroundColor(.white)
            .frame(height: 62)

            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            Text(subtitle)
                .font(.title3)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                // Wraps rather than clips at large Dynamic Type sizes, where
                // `.title3` grows well past the width these questions assume.
                .fixedSize(horizontal: false, vertical: true)
        }
        // 24, matching the option cards' 20pt gutter closely enough to read as
        // one column — the header used to be inset a further 12pt on each side,
        // which is what pushed "Select how you'll complete your mile" onto
        // three lines on a small phone.
        .padding(.horizontal, 24)
    }
}

/// The symbol in an option card's leading slot.
struct WizardOptionGlyph: View {
    let icon: String
    var width: CGFloat = 50

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 30))
            .frame(width: width)
    }
}

/// The trailing chevron an option card wears by default.
struct WizardOptionChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.title2)
            .fontWeight(.semibold)
    }
}

/// The wizard's option card.
///
/// `featured` brightens the surface so one option can read as the special
/// one, `badge` is the small pill beside the title (the ghost race's NEW
/// flag), `leading` is the glyph slot (a drawn ghost, not just a symbol), and
/// `accessory` replaces the trailing chevron with a readout.
struct WizardOptionCard<Leading: View, Accessory: View>: View {
    let leading: Leading
    let title: String
    let subtitle: String
    var featured: Bool = false
    var badge: String? = nil
    let accessory: Accessory
    let action: () -> Void

    init(
        @ViewBuilder leading: () -> Leading,
        title: String,
        subtitle: String,
        featured: Bool = false,
        badge: String? = nil,
        @ViewBuilder accessory: () -> Accessory,
        action: @escaping () -> Void
    ) {
        self.leading = leading()
        self.title = title
        self.subtitle = subtitle
        self.featured = featured
        self.badge = badge
        self.accessory = accessory()
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                leading

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        // The title is the one thing here that CANNOT wrap or
                        // clip: at 28pt "Just Track It" wants ~190pt and a
                        // 375pt phone leaves the text column ~189pt, so it was
                        // breaking to two lines (or truncating once the badge
                        // took its share). Scaling is the right trade — a
                        // title a few percent smaller reads fine, a title
                        // reading "Just Track…" does not.
                        Text(title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .allowsTightening(true)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .tracking(0.8)
                                .foregroundColor(.black.opacity(0.8))
                                .lineLimit(1)
                                // Safe here where `.fixedSize` normally isn't:
                                // every badge is a short literal ("NEW",
                                // "2 INVITES"), never open-ended data, so it
                                // can't publish a minimum width that starves
                                // the row.
                                .fixedSize()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.yellow))
                        }
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .opacity(0.9)
                        .multilineTextAlignment(.leading)
                        // Wraps to as many lines as it needs instead of
                        // truncating — which is why the subtitles were never
                        // the ones getting cut off.
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                accessory
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(featured ? 0.24 : 0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(featured ? 0.6 : 0.3), lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Forward slides in from the trailing edge, Back from the leading edge — so
/// a wizard reads as depth rather than as unrelated crossfades.
enum WizardMotion {
    static func transition(goingBack: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: goingBack ? .leading : .trailing)
                .combined(with: .opacity),
            removal: .move(edge: goingBack ? .trailing : .leading)
                .combined(with: .opacity)
        )
    }
}
